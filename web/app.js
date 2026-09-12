const config = window.STREAMFORGE_CONFIG;
const login = document.querySelector('#login');
const app = document.querySelector('#app');
const fileInput = document.querySelector('#file');
const selectedFile = document.querySelector('#selected-file');
const uploadButton = document.querySelector('#upload');
const statusRegion = document.querySelector('#status-region');
const message = document.querySelector('#message');
const result = document.querySelector('#result');
const resultTitle = document.querySelector('#result-title');
const resultBatch = document.querySelector('#result-batch');
const totalRecords = document.querySelector('#total-records');
const validRecords = document.querySelector('#valid-records');
const invalidRecords = document.querySelector('#invalid-records');
const resultFile = document.querySelector('#result-file');
const resultTime = document.querySelector('#result-time');
const downloadClean = document.querySelector('#download-clean');
const downloadRejected = document.querySelector('#download-rejected');

const SESSION_EXPIRED = 'Your session expired. Please sign in again.';

// Treat a token that dies within the next 30s as already dead, so a request
// cannot expire mid-flight.
const TOKEN_SKEW_MS = 30_000;
const POLL_TIMEOUT_MS = 5 * 60_000;

function token() {
  const raw = sessionStorage.getItem('id_token');
  if (!raw) return null;
  try {
    const b64 = raw.split('.')[1].replace(/-/g, '+').replace(/_/g, '/');
    const { exp } = JSON.parse(atob(b64.padEnd(Math.ceil(b64.length / 4) * 4, '=')));
    if (!exp || exp * 1000 - TOKEN_SKEW_MS <= Date.now()) return null;
  } catch {
    return null; // unparseable token is no token
  }
  return raw;
}

function signOut(reason) {
  sessionStorage.removeItem('id_token');
  login.hidden = false;
  app.hidden = true;
  result.hidden = true;
  if (reason) setStatus(reason, 'error');
}

// The portal pages are ES modules and cannot see these consts, so share the
// session handling rather than letting a second copy drift out of sync.
window.StreamForge = { token, signOut };

function base64UrlEncode(bytes) {
  let binary = '';
  bytes.forEach((byte) => { binary += String.fromCharCode(byte); });
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

async function createPkcePair() {
  const verifierBytes = crypto.getRandomValues(new Uint8Array(32));
  const verifier = base64UrlEncode(verifierBytes);
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(verifier));
  return { verifier, challenge: base64UrlEncode(new Uint8Array(digest)) };
}

function setStatus(text, state = 'processing') {
  message.textContent = text;
  statusRegion.hidden = false;
  statusRegion.className = `status-region is-${state}`;
  window.dispatchEvent(new CustomEvent('streamforge:status', { detail: { text, state } }));
}

function formatTimestamp(timestamp) {
  if (!timestamp) return '';
  return `Processed ${new Intl.DateTimeFormat(undefined, { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(timestamp))}`;
}

function renderResult(status) {
  result.hidden = false;
  resultTitle.textContent = 'Batch complete';
  resultBatch.textContent = `Batch ${status.batch_id}`;
  totalRecords.textContent = status.total_records ?? '—';
  validRecords.textContent = status.valid_records ?? '—';
  invalidRecords.textContent = status.invalid_records ?? '—';
  resultFile.textContent = status.source_filename ? `Source: ${status.source_filename}` : '';
  resultTime.textContent = formatTimestamp(status.processed_timestamp);

  const downloads = status.downloads || {};
  downloadClean.hidden = !downloads.clean;
  downloadRejected.hidden = !downloads.rejected;
  if (downloads.clean) downloadClean.href = downloads.clean;
  if (downloads.rejected) downloadRejected.href = downloads.rejected;
  window.dispatchEvent(new CustomEvent('streamforge:result', { detail: status }));
}

async function exchangeCode() {
  const code = new URLSearchParams(location.search).get('code');
  if (!code) return;
  const verifier = sessionStorage.getItem('pkce_verifier');
  if (!verifier) throw new Error('Your sign-in session expired. Please sign in again.');
  const response = await fetch(`${config.cognitoDomain}/oauth2/token`, {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ grant_type: 'authorization_code', client_id: config.clientId, code, code_verifier: verifier, redirect_uri: config.redirectUri }),
  });
  const payload = await response.json();
  if (!response.ok) throw new Error(payload.error_description || 'Sign-in failed');
  sessionStorage.setItem('id_token', payload.id_token);
  sessionStorage.removeItem('pkce_verifier');
  // Keep the hash: it is the portal route, and dropping it would bounce the
  // user back to Upload after every sign-in.
  history.replaceState({}, '', `${config.redirectUri}${location.hash}`);
}

login.onclick = async () => {
  try {
    const { verifier, challenge } = await createPkcePair();
    sessionStorage.setItem('pkce_verifier', verifier);
    const url = new URL(`${config.cognitoDomain}/login`);
    url.search = new URLSearchParams({
      client_id: config.clientId,
      response_type: 'code',
      scope: 'openid email',
      redirect_uri: config.redirectUri,
      code_challenge_method: 'S256',
      code_challenge: challenge,
    });
    location.assign(url);
  } catch (error) {
    // crypto.subtle is undefined outside a secure context, so this button
    // would otherwise appear dead over plain http.
    setStatus(error instanceof Error ? error.message : 'Could not start sign-in', 'error');
  }
};

fileInput.onchange = () => {
  const file = fileInput.files[0];
  selectedFile.hidden = !file;
  selectedFile.textContent = file ? `${file.name} · ${(file.size / 1024).toFixed(1)} KB` : '';
  uploadButton.disabled = !file;
};

async function api(path, options = {}) {
  const idToken = token();
  if (!idToken) {
    signOut(SESSION_EXPIRED);
    throw new Error(SESSION_EXPIRED);
  }

  const response = await fetch(`${config.apiEndpoint}${path}`, { ...options, headers: { ...options.headers, Authorization: `Bearer ${idToken}` } });
  if (response.status === 401 || response.status === 403) {
    signOut(SESSION_EXPIRED);
    throw new Error(SESSION_EXPIRED);
  }

  // Gateway errors and timeouts are not always JSON.
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(payload.message || `Request failed (${response.status})`);
  return payload;
}

async function uploadToS3(uploadUrl, file) {
  const response = await fetch(uploadUrl, { method: 'PUT', headers: { 'content-type': 'text/csv' }, body: file });
  if (response.ok) return;
  const errorBody = await response.text();
  const errorCode = errorBody.match(/<Code>([^<]+)<\/Code>/)?.[1];
  const errorMessage = errorBody.match(/<Message>([^<]+)<\/Message>/)?.[1];
  const detail = [errorCode, errorMessage].filter(Boolean).join(': ');
  throw new Error(`S3 upload failed (${response.status})${detail ? ` — ${detail}` : ''}`);
}

uploadButton.onclick = async () => {
  const file = fileInput.files[0];
  if (!file) return;
  uploadButton.disabled = true;
  result.hidden = true;

  try {
    setStatus('Requesting a secure upload URL…');
    const upload = await api('/uploads', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ filename: file.name, size: file.size }) });
    setStatus('Uploading encrypted file…');
    await uploadToS3(upload.upload_url, file);
    setStatus('Validating rows and preparing outputs…');

    const deadline = Date.now() + POLL_TIMEOUT_MS;
    const poll = async () => {
      try {
        const status = await api(`/status?key=${encodeURIComponent(upload.key)}`);
        if (status.status === 'PROCESSING') {
          if (Date.now() > deadline) {
            setStatus('Still processing after 5 minutes. Your file was uploaded — check back shortly.', 'error');
            uploadButton.disabled = false;
            return;
          }
          setStatus('Validating rows and preparing outputs…');
          setTimeout(poll, 3000);
          return;
        }
        renderResult(status);
        setStatus('Processing complete. Your outputs are ready.', 'complete');
        uploadButton.disabled = false;
      } catch (error) {
        setStatus(error instanceof Error ? error.message : 'Status check failed', 'error');
        uploadButton.disabled = false;
      }
    };
    poll();
  } catch (error) {
    setStatus(error instanceof Error ? error.message : 'Upload failed', 'error');
    uploadButton.disabled = false;
  }
};

exchangeCode().then(() => {
  if (token()) {
    login.hidden = true;
    app.hidden = false;
    // Portal pages rendered a signed-out state before the token arrived;
    // this tells the router to rebuild them.
    window.dispatchEvent(new CustomEvent('streamforge:signedin'));
  }
}).catch((error) => setStatus(error.message, 'error'));
