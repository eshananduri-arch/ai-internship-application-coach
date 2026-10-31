const base = document.querySelector('meta[name="api-base"]').content.replace(/\/$/, '');
let csrf = '';

export class ApiError extends Error {
  constructor(message, status = 0) { super(message); this.status = status; }
}

async function request(path, { method = 'GET', body, key, binary = false, signal } = {}) {
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
    response = await fetch(base + path, { method, headers, body, credentials: 'same-origin', signal: signal ? AbortSignal.any([signal, AbortSignal.timeout(30000)]) : AbortSignal.timeout(30000) });
  } catch (error) {
    if (signal?.aborted) throw error;
    throw new ApiError('The backend could not be reached. Check your connection and try again.');
  }
  if (!response.ok) {
    let message = `The request failed (${response.status}). Please try again.`;
    try { const data = await response.json(); if (typeof data.message === 'string') message = data.message.slice(0, 300); } catch { /* HTML errors are never displayed. */ }
    if (response.status === 404 || response.status === 503) message = 'The Python backend is not connected yet. This local frontend is ready for integration.';
    throw new ApiError(message, response.status);
  }
  if (binary) return response;
  try { return await response.json(); } catch { throw new ApiError('The backend returned an unreadable response. Please try again.'); }
}

export async function session() {
  csrf = '';
  const data = await request('/session');
  if (typeof data.csrf_token !== 'string' || !data.csrf_token) throw new ApiError('The backend did not create a private session.');
  csrf = data.csrf_token;
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
