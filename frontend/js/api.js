const BASE = '/api';

async function request(method, path, body = null, formEncoded = false) {
  const token = localStorage.getItem('token');
  const headers = {};

  if (token) headers['Authorization'] = `Bearer ${token}`;

  let bodyStr = null;
  if (body !== null) {
    if (formEncoded) {
      headers['Content-Type'] = 'application/x-www-form-urlencoded';
      bodyStr = new URLSearchParams(body).toString();
    } else {
      headers['Content-Type'] = 'application/json';
      bodyStr = JSON.stringify(body);
    }
  }

  const res = await fetch(`${BASE}${path}`, { method, headers, body: bodyStr });

  if (res.status === 401) {
    localStorage.removeItem('token');
    localStorage.removeItem('user');
    window.location.reload();
    return null;
  }

  if (!res.ok) {
    const err = await res.json().catch(() => ({ detail: 'Unbekannter Fehler' }));
    throw new Error(err.detail || `HTTP ${res.status}`);
  }

  if (res.status === 204) return null;
  return res.json();
}

export const api = {
  get:    (path)        => request('GET',    path),
  post:   (path, body)  => request('POST',   path, body),
  put:    (path, body)  => request('PUT',    path, body),
  delete: (path)        => request('DELETE', path),

  login: (username, password) =>
    request('POST', '/auth/token', { username, password }, true),

  setupRequired: () => request('GET', '/auth/setup-required'),
  setup: (data)      => request('POST', '/auth/setup', data),
};
