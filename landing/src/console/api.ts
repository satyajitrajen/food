// FoodPOS Console API layer — talks to the Go SaaS backend.
function apiBaseUrl(): string {
  const env = (import.meta as any).env;
  return (env && env.VITE_FOODPOS_API_URL) || 'https://food.nexorytechnologies.com';
}
export const API_BASE: string = apiBaseUrl();

export type ConsoleRole = 'owner' | 'admin';

export interface ConsoleSession {
  token: string;
  refresh: string;
  role: ConsoleRole;
  name: string;
  email: string;
  orgId?: string;
  orgName?: string;
}

export class ApiError extends Error {
  status: number;
  code: string;
  constructor(status: number, code: string, message: string) {
    super(message);
    this.status = status;
    this.code = code;
  }
}

async function request(
  path: string,
  opts: { method?: string; body?: unknown; token?: string; retry?: boolean } = {},
): Promise<any> {
  const headers: Record<string, string> = { 'Content-Type': 'application/json' };
  if (opts.token) headers.Authorization = `Bearer ${opts.token}`;
  const res = await fetch(`${API_BASE}${path}`, {
    method: opts.method ?? 'GET',
    headers,
    body: opts.body === undefined ? undefined : JSON.stringify(opts.body),
  });
  let data: any = null;
  try {
    data = await res.json();
  } catch {
    /* empty body */
  }
  if (res.status === 401 && opts.token && !opts.retry) {
    const refreshed = await refreshTokens();
    if (refreshed) return request(path, { ...opts, retry: true });
  }
  if (!res.ok) {
    const err = data?.error ?? {};
    throw new ApiError(res.status, err.code ?? 'error', err.message ?? `Request failed (${res.status})`);
  }
  return data;
}

// ---- session helpers ----
const SESSION_KEY = 'foodpos.console.session.v1';

export function loadSession(): ConsoleSession | null {
  try {
    const raw = localStorage.getItem(SESSION_KEY);
    if (!raw) return null;
    const parsed = JSON.parse(raw) as ConsoleSession;
    return parsed.token ? parsed : null;
  } catch {
    return null;
  }
}

export function saveSession(s: ConsoleSession) {
  localStorage.setItem(SESSION_KEY, JSON.stringify(s));
}

export function clearSession() {
  localStorage.removeItem(SESSION_KEY);
}

async function refreshTokens(): Promise<boolean> {
  const session = loadSession();
  if (!session) return false;
  try {
    const data = await request(
      session.role === 'admin' ? '/api/v1/admin/refresh' : '/api/v1/auth/account/refresh',
      { method: 'POST', body: { refresh_token: session.refresh } },
    );
    if (data && data.token && data.refresh_token) {
      saveSession({
        ...session,
        token: data.token,
        refresh: data.refresh_token,
      });
      return true;
    }
  } catch {
    /* fall through */
  }
  clearSession();
  return false;
}

// ---- auth ----
export async function loginOwner(email: string, password: string): Promise<ConsoleSession> {
  const data = await request('/api/v1/auth/account/login', {
    method: 'POST',
    body: { email, password },
  });
  const org = data.org ?? {};
  const session: ConsoleSession = {
    token: data.token,
    refresh: data.refresh_token,
    role: 'owner',
    name: data.account?.name ?? email,
    email,
    orgId: String(org.id ?? ''),
    orgName: String(org.name ?? ''),
  };
  saveSession(session);
  return session;
}

export async function loginAdmin(email: string, password: string): Promise<ConsoleSession> {
  const data = await request('/api/v1/admin/login', {
    method: 'POST',
    body: { email, password },
  });
  const session: ConsoleSession = {
    token: data.token,
    refresh: data.refresh_token,
    role: 'admin',
    name: data.admin?.name ?? email,
    email,
  };
  saveSession(session);
  return session;
}

export interface RegisterPayload {
  org_name: string;
  owner_name: string;
  email: string;
  password: string;
  gstin?: string;
  outlet_name: string;
  terminal?: string;
}

export async function registerOrg(payload: RegisterPayload): Promise<any> {
  return request('/api/v1/auth/register', { method: 'POST', body: payload });
}

// ---- owner APIs ----
export const api = {
  me: () => request('/api/v1/saas/me', { token: sessionToken() }),
  org: () => request('/api/v1/saas/org', { token: sessionToken() }),
  createOutlet: (body: Record<string, unknown>) =>
    request('/api/v1/saas/outlets', { method: 'POST', body, token: sessionToken() }),
  createStaff: (body: Record<string, unknown>) =>
    request('/api/v1/saas/staff', { method: 'POST', body, token: sessionToken() }),
  rotateCode: () =>
    request('/api/v1/saas/org/rotate-code', { method: 'POST', token: sessionToken() }),
  cancelSubscription: () =>
    request('/api/v1/saas/subscription/cancel', { method: 'POST', token: sessionToken() }),

  adminOrgs: (status?: string) =>
    request(`/api/v1/admin/orgs${status ? `?status=${encodeURIComponent(status)}` : ''}`, {
      token: sessionToken(),
    }),
  adminOrgDetail: (id: string) => request(`/api/v1/admin/orgs/${id}`, { token: sessionToken() }),
  adminActivate: (id: string, body: Record<string, unknown>) =>
    request(`/api/v1/admin/orgs/${id}/activate`, { method: 'POST', body, token: sessionToken() }),
  adminExtend: (id: string, days: number, notes?: string) =>
    request(`/api/v1/admin/orgs/${id}/extend`, {
      method: 'POST',
      body: { days, notes },
      token: sessionToken(),
    }),
  adminSuspend: (id: string, notes?: string) =>
    request(`/api/v1/admin/orgs/${id}/suspend`, { method: 'POST', body: { notes }, token: sessionToken() }),
  adminCancel: (id: string, notes?: string) =>
    request(`/api/v1/admin/orgs/${id}/cancel`, { method: 'POST', body: { notes }, token: sessionToken() }),
  adminStats: () => request('/api/v1/admin/stats', { token: sessionToken() }),
};

function sessionToken(): string {
  return loadSession()?.token ?? '';
}

// ---- invoice PDF (download via blob, auth header) ----
export async function downloadInvoicePdf(invoiceId: string, role: ConsoleRole): Promise<void> {
  const token = sessionToken();
  const base = role === 'admin' ? '/api/v1/admin' : '/api/v1/saas';
  const res = await fetch(`${API_BASE}${base}/invoices/${invoiceId}/pdf`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  if (!res.ok) throw new Error('Could not download the invoice');
  const blob = await res.blob();
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = `invoice-${invoiceId}.pdf`;
  a.click();
  URL.revokeObjectURL(url);
}
