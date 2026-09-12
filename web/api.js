/**
 * Shared API client for the portal pages.
 *
 * Session handling lives in app.js and is reached through window.StreamForge.
 * app.js is a classic script, so its consts are not importable; sharing the
 * implementation keeps one definition of "is this token usable".
 */

const config = window.STREAMFORGE_CONFIG;

/** Thrown when the viewer is not signed in, so pages can render a prompt. */
export class SessionError extends Error {}

const cache = new Map();

function session() {
  // app.js may not have run yet if a module loads unusually early.
  return window.StreamForge || { token: () => null, signOut: () => {} };
}

export async function api(path, options = {}) {
  const { token, signOut } = session();
  const idToken = token();
  if (!idToken) {
    signOut();
    throw new SessionError('Sign in to view this page.');
  }

  let response;
  try {
    response = await fetch(`${config.apiEndpoint}${path}`, {
      ...options,
      headers: { ...options.headers, Authorization: `Bearer ${idToken}` },
    });
  } catch {
    // fetch only rejects on network failure, never on an HTTP error status.
    throw new Error('Could not reach the API. Check your connection.');
  }

  if (response.status === 401 || response.status === 403) {
    signOut();
    throw new SessionError('Your session expired. Please sign in again.');
  }

  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(payload.message || `Request failed (${response.status})`);
  }
  return payload;
}

/**
 * api() with a short-lived cache, so revisiting a page does not re-query AWS.
 * Session errors are never cached.
 */
export async function cachedApi(path, ttlMs = 60_000) {
  const hit = cache.get(path);
  if (hit && Date.now() < hit.expires) return hit.value;

  const value = await api(path);
  cache.set(path, { value, expires: Date.now() + ttlMs });
  return value;
}

export function clearCache() {
  cache.clear();
}

export function isSignedIn() {
  return Boolean(session().token());
}
