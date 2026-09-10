/**
 * Checks for the session handling in app.js.
 *
 * app.js is a plain browser script, so it is loaded into a vm context with the
 * handful of browser globals it touches at load time. Run with:
 *   node --test web/app.test.js
 */

const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const SOURCE = fs.readFileSync(path.join(__dirname, 'app.js'), 'utf8');

/** Loads app.js fresh and hands back its globals and stub elements. */
function loadApp(storedToken) {
  const store = new Map();
  if (storedToken !== undefined) store.set('id_token', storedToken);

  // app.js holds its elements in `const`s, which do not attach to the vm
  // global, so keep a handle on every element the script asks for.
  const elements = new Map();
  const querySelector = (selector) => {
    if (!elements.has(selector)) {
      elements.set(selector, { hidden: false, textContent: '', className: '', href: '', files: [] });
    }
    return elements.get(selector);
  };

  const context = {
    document: { querySelector },
    window: { STREAMFORGE_CONFIG: { apiEndpoint: '', cognitoDomain: '', clientId: '', redirectUri: '' } },
    sessionStorage: {
      getItem: (k) => (store.has(k) ? store.get(k) : null),
      setItem: (k, v) => store.set(k, v),
      removeItem: (k) => store.delete(k),
    },
    location: { search: '' },
    atob: (b64) => Buffer.from(b64, 'base64').toString('binary'),
    btoa: (bin) => Buffer.from(bin, 'binary').toString('base64'),
    console,
    fetch: () => Promise.reject(new Error('network disabled in tests')),
  };
  vm.createContext(context);
  vm.runInContext(SOURCE, context);
  return { context, store, elements };
}

/** Builds a JWT whose payload expires `secondsFromNow` from now. */
function jwt(secondsFromNow) {
  const payload = { exp: Math.floor(Date.now() / 1000) + secondsFromNow };
  const body = Buffer.from(JSON.stringify(payload))
    .toString('base64')
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '');
  return `header.${body}.signature`;
}

test('a valid unexpired token is returned', () => {
  const { context } = loadApp(jwt(3600));
  assert.ok(context.token(), 'expected the token to be usable');
});

test('no stored token yields null', () => {
  const { context } = loadApp();
  assert.strictEqual(context.token(), null);
});

test('an expired token is rejected', () => {
  const { context } = loadApp(jwt(-1));
  assert.strictEqual(context.token(), null, 'expired token must not count as signed in');
});

test('a token expiring inside the skew window is rejected', () => {
  const { context } = loadApp(jwt(5));
  assert.strictEqual(context.token(), null, 'token would die mid-request');
});

test('a token just outside the skew window is accepted', () => {
  const { context } = loadApp(jwt(120));
  assert.ok(context.token());
});

test('a malformed token is rejected rather than throwing', () => {
  for (const bad of ['', 'not-a-jwt', 'a.b', 'a.!!!not-base64!!!.c', 'a.e30.c']) {
    const { context } = loadApp(bad);
    assert.strictEqual(context.token(), null, `expected null for ${JSON.stringify(bad)}`);
  }
});

test('signOut clears the token and restores the sign-in button', () => {
  const { context, store, elements } = loadApp(jwt(3600));
  context.signOut('Your session expired.');

  assert.strictEqual(store.has('id_token'), false, 'stale token must be cleared');
  assert.strictEqual(elements.get('#login').hidden, false, 'sign-in button must come back');
  assert.strictEqual(elements.get('#app').hidden, true, 'upload form must be hidden');
  assert.strictEqual(elements.get('#message').textContent, 'Your session expired.');
});

test('a signed-out user is not left stranded after the token expires', () => {
  // The original bug: any stored token counted as signed in, so an expired
  // token hid the sign-in button forever.
  const { context } = loadApp(jwt(-1));
  assert.strictEqual(context.token(), null);
});
