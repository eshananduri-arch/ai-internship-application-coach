const base = document.querySelector('meta[name="api-base"]').content.replace(/\/$/, '');
let csrf = '';

export class ApiError extends Error {
  constructor(message, status = 0, transient = false) { super(message); this.status = status; this.transient = transient; }
}

async function request(path, { method = 'GET', body, key, binary = false, signal, timeout = 30000 } = {}) {
  const headers = { Accept: binary ? '*/*' : 'application/json' };
  if (method !== 'GET') {
    if (!csrf) throw new ApiError('Your private session is unavailable. Please try again.');
    headers['X-CSRF-Token'] = csrf;
    if (key) headers['Idempotency-Key'] = key;
    if (!(body instanceof FormData)) {
      headers['Content-Type'] = 'application/json';
      body = JSON.stringify(body);
    }
  }
  let response;
  try {
    response = await fetch(base + path, { method, headers, body, credentials: 'same-origin', signal: signal ? AbortSignal.any([signal, AbortSignal.timeout(timeout)]) : AbortSignal.timeout(timeout) });
  } catch (error) {
    if (signal?.aborted) throw error;
    throw new ApiError('The backend could not be reached. Check your connection and try again.', 0, true);
  }
  if (!response.ok) {
    let message = `The request failed (${response.status}). Please try again.`;
    let hasMessage = false, code = '';
    try { const data = await response.json(); code = typeof data.code === 'string' ? data.code : ''; if (typeof data.message === 'string') { message = data.message.slice(0, 300); hasMessage = true; } } catch { /* HTML errors are never displayed. */ }
    if (!hasMessage && [502, 503, 504].includes(response.status)) message = 'The server is temporarily unavailable. Please try again shortly.';
    const transient = [502, 503, 504].includes(response.status) && !['database_unconfigured', 'coaching_unconfigured'].includes(code);
    throw new ApiError(message, response.status, transient);
  }
  if (binary) return response;
  try { return await response.json(); } catch { throw new ApiError('The backend returned an unreadable response. Please try again.'); }
}

// Retry only this pre-upload GET. Uploads, decisions and model requests are never replayed here.
export async function session(onWaiting = () => {}) {
  csrf = '';
  const deadline = Date.now() + 90000;
  for (let attempt = 0; attempt < 10; attempt++) {
    try {
      const remaining = deadline - Date.now();
      if (remaining <= 0) break;
      const data = await request('/session', { timeout: Math.min(20000, remaining) });
      if (typeof data.csrf_token !== 'string' || !data.csrf_token) throw new ApiError('The backend did not create a private session.');
      csrf = data.csrf_token;
      return;
    } catch (error) {
      if (!(error instanceof ApiError) || !error.transient) throw error;
      const wait = Math.min(1000 * 2 ** attempt, 10000);
      if (attempt === 9 || Date.now() + wait >= deadline) break;
      onWaiting();
      await new Promise(resolve => setTimeout(resolve, wait));
    }
  }
  throw new ApiError('The server is temporarily unavailable. Your resume has not been submitted. Please try again shortly.', 503);
}

export async function catalog() {
  try {
    const companies = await request('/companies');
    if (!Array.isArray(companies) || !companies.length) throw new Error();
    const rows = await Promise.all(companies.map(async company => {
      const name = typeof company === 'string' ? company : company.name;
      if (!name) throw new Error();
      const roles = await request('/roles?company=' + encodeURIComponent(name));
      if (!Array.isArray(roles)) throw new Error();
      return roles.map(role => ({ ...role, company: name, role: role.role || role.role_title }));
    }));
    return { rows: rows.flat(), offline: false };
  } catch {
    const response = await fetch(new URL('../data/roles.json', import.meta.url));
    if (!response.ok) throw new ApiError('The role catalog could not be loaded. Reload this page.');
    return { rows: await response.json(), offline: true };
  }
}

export function generate(input, file, key, signal) {
  const body = new FormData();
  for (const [name, value] of Object.entries(input)) body.append(name, value);
  body.append('resume', file);
  return request('/analyses', { method: 'POST', body, key, signal });
}
export const status = (id, signal) => request('/analyses/' + encodeURIComponent(id), { signal });
export const decide = (id, body, key) => request('/analyses/' + encodeURIComponent(id) + '/decision', { method: 'POST', body, key });
export const download = (id, format) => request('/applications/' + encodeURIComponent(id) + '/download?format=' + encodeURIComponent(format), { binary: true });
