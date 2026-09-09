import React, { useCallback, useEffect, useState } from 'react';
import { useRouter } from '../router';
import {
  ApiError,
  ConsoleSession,
  api,
  clearSession,
  downloadInvoicePdf,
  loadSession,
  loginAdmin,
  loginOwner,
  registerOrg,
  saveSession,
} from './api';

// ---- helpers ----
function fmtRs(paise: number): string {
  return `Rs. ${(paise / 100).toLocaleString('en-IN', { maximumFractionDigits: 2 })}`;
}
function fmtDate(v: string | null | undefined): string {
  if (!v) return '—';
  const d = new Date(v);
  return isNaN(d.getTime()) ? '—' : d.toLocaleDateString('en-IN', { day: '2-digit', month: 'short', year: 'numeric' });
}
function errMessage(e: unknown): string {
  return e instanceof ApiError ? e.message : e instanceof Error ? e.message : 'Something went wrong';
}

// ================= Console root / layout =================
export const ConsoleApp: React.FC = () => {
  const { currentPath } = useRouter();
  const [session, setSession] = useState<ConsoleSession | null>(() => loadSession());

  useEffect(() => {
    // re-read session when the token changes via another tab? keep simple
    setSession(loadSession());
  }, [currentPath]);

  if (currentPath === '/console/login') {
    return <LoginPage />;
  }
  if (currentPath === '/console/register') {
    return <RegisterPage />;
  }
  if (!session) {
    return <RedirectToLogin />;
  }
  return <Layout session={session} onLogout={() => { clearSession(); window.location.hash = '/console/login'; }} />;
};

const RedirectToLogin: React.FC = () => {
  const { navigate } = useRouter();
  useEffect(() => navigate('/console/login'), [navigate]);
  return null;
};

const Layout: React.FC<{ session: ConsoleSession; onLogout: () => void }> = ({ session, onLogout }) => {
  const { navigate } = useRouter();
  return (
    <div className="console-root">
      <header className="console-topbar">
        <div className="console-brand">
          <span style={{ background: 'var(--orange-primary)', width: 28, height: 28, borderRadius: 8, display: 'inline-flex', alignItems: 'center', justifyContent: 'center', color: '#fff', fontWeight: 900 }}>F</span>
          FoodPOS Console
        </div>
        <div className="console-user">
          <span>{session.name}</span>
          <span className="console-badge badge-ok">{session.role === 'admin' ? 'Superadmin' : 'Owner'}</span>
          <button className="console-btn console-btn-ghost console-btn-sm" onClick={() => navigate('/')}>Landing</button>
          <button className="console-btn console-btn-danger console-btn-sm" onClick={onLogout}>Logout</button>
        </div>
      </header>
      <main className="console-main">
        {session.role === 'admin' ? <SuperAdminPanel /> : <OwnerPanel />}
      </main>
    </div>
  );
};

// ================= Login =================
const LoginPage: React.FC = () => {
  const { navigate } = useRouter();
  const [mode, setMode] = useState<'owner' | 'admin'>('owner');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    setBusy(true);
    setError('');
    try {
      const session = mode === 'owner' ? await loginOwner(email, password) : await loginAdmin(email, password);
      saveSession(session);
      navigate('/console');
    } catch (err) {
      setError(errMessage(err));
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="console-login-wrap">
      <div className="console-login-card">
        <h2>FoodPOS Console</h2>
        <p className="hint">Sign in to manage your restaurant or the platform.</p>
        <div className="console-tabs">
          <button className={mode === 'owner' ? 'active' : ''} onClick={() => setMode('owner')}>Restaurant Owner</button>
          <button className={mode === 'admin' ? 'active' : ''} onClick={() => setMode('admin')}>Superadmin</button>
        </div>
        {error && <div className="console-banner console-banner-error">{error}</div>}
        <form className="console-form" onSubmit={submit}>
          <div className="console-field">
            <label>E-mail</label>
            <input className="console-input" type="email" required value={email}
              onChange={(e) => setEmail(e.target.value)} placeholder="you@restaurant.com" />
          </div>
          <div className="console-field">
            <label>Password</label>
            <input className="console-input" type="password" required value={password}
              onChange={(e) => setPassword(e.target.value)} placeholder="••••••••" />
          </div>
          <button className="console-btn console-btn-primary" disabled={busy}>
            {busy ? 'Signing in…' : 'Sign in'}
          </button>
        </form>
        {mode === 'owner' && (
          <p style={{ marginTop: 16, textAlign: 'center' }}>
            New here?{' '}
            <button className="console-link" onClick={() => navigate('/console/register')}>
              Create your account
            </button>
          </p>
        )}
      </div>
    </div>
  );
};

// ================= Registration =================
const RegisterPage: React.FC = () => {
  const { navigate } = useRouter();
  const [form, setForm] = useState({ org_name: '', owner_name: '', email: '', password: '', outlet_name: '', gstin: '' });
  const [error, setError] = useState('');
  const [info, setInfo] = useState<Record<string, any> | null>(null);
  const [busy, setBusy] = useState(false);

  const set = (k: string) => (e: React.ChangeEvent<HTMLInputElement>) => setForm((f) => ({ ...f, [k]: e.target.value }));

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    setBusy(true);
    setError('');
    try {
      const data = await registerOrg(form);
      await loginOwner(form.email, form.password);
      setInfo(data);
    } catch (err) {
      setError(errMessage(err));
    } finally {
      setBusy(false);
    }
  };

  if (info) {
    return (
      <div className="console-login-wrap">
        <div className="console-login-card">
          <h2>Welcome to FoodPOS 🎉</h2>
          <p className="hint">Your 14-day trial is live. Keep these safe:</p>
          <div className="console-field" style={{ marginBottom: 14 }}>
            <label>Organization code (terminal setup)</label>
            <div className="console-code">{String(info.org_code ?? '')}</div>
          </div>
          <div className="console-field" style={{ marginBottom: 18 }}>
            <label>Initial POS admin PIN (shown once)</label>
            <div className="console-code">{String(info.admin_pin ?? '')}</div>
          </div>
          <div className="console-banner console-banner-info">
            Terminal: open the FoodPOS app → enter the org code above.
          </div>
          <button className="console-btn console-btn-primary" onClick={() => navigate('/console')}>
            Open my dashboard
          </button>
        </div>
      </div>
    );
  }

  return (
    <div className="console-login-wrap">
      <div className="console-login-card">
        <h2>Create your account</h2>
        <p className="hint">One outlet is created for you; add more later from your plan.</p>
        {error && <div className="console-banner console-banner-error">{error}</div>}
        <form className="console-form" onSubmit={submit}>
          <input className="console-input" required placeholder="Restaurant name" value={form.org_name} onChange={set('org_name')} />
          <input className="console-input" required placeholder="Your name" value={form.owner_name} onChange={set('owner_name')} />
          <input className="console-input" required type="email" placeholder="E-mail" value={form.email} onChange={set('email')} />
          <input className="console-input" required type="password" minLength={8} placeholder="Password (min 8 chars)" value={form.password} onChange={set('password')} />
          <input className="console-input" required placeholder="First outlet name (e.g. Baner)" value={form.outlet_name} onChange={set('outlet_name')} />
          <input className="console-input" placeholder="GSTIN (optional)" value={form.gstin} onChange={set('gstin')} />
          <button className="console-btn console-btn-primary" disabled={busy}>
            {busy ? 'Creating…' : 'Start 14-day free trial'}
          </button>
        </form>
        <p style={{ marginTop: 14, textAlign: 'center' }}>
          <button className="console-link" onClick={() => navigate('/console/login')}>Back to sign in</button>
        </p>
      </div>
    </div>
  );
};

// ================= Owner panel =================
interface OwnerOrg {
  org: any;
  subscription: any;
  outlets: any[];
  staff: any[];
  invoices: any[];
  events: any[];
}

const OwnerPanel: React.FC = () => {
  const [data, setData] = useState<OwnerOrg | null>(null);
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');
  const [busy, setBusy] = useState(false);
  const [showNewOutlet, setShowNewOutlet] = useState(false);
  const [outletForm, setOutletForm] = useState({ name: '', terminal: '' });
  const [staffForm, setStaffForm] = useState({ name: '', role: 'waiter', pin: '', outlet_id: '' });

  const load = useCallback(async () => {
    try {
      setError('');
      const org = await api.org();
      setData(org as OwnerOrg);
    } catch (e) {
      setError(errMessage(e));
    }
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  if (!data) {
    return (
      <div>
        <h1 className="console-title">Dashboard</h1>
        {error && <div className="console-banner console-banner-error">{error}</div>}
        <p>Loading…</p>
      </div>
    );
  }

  const org = data.org;
  const sub = data.subscription || {};
  const plan = sub.plan || {};
  const end = sub.current_period_end || sub.trial_ends_at;

  const run = async (fn: () => Promise<any>, okMsg: string) => {
    setBusy(true);
    setError('');
    setNotice('');
    try {
      await fn();
      setNotice(okMsg);
      await load();
    } catch (e) {
      setError(errMessage(e));
    } finally {
      setBusy(false);
    }
  };

  return (
    <div>
      <h1 className="console-title">Dashboard</h1>
      <p className="console-subtitle">{org.name} · {org.id}</p>
      {error && <div className="console-banner console-banner-error">{error}</div>}
      {notice && <div className="console-banner console-banner-ok">{notice}</div>}

      <div className="console-cards" style={{ marginBottom: 18 }}>
        <div className="console-card console-stat">
          <div className="stat-value">{(sub.status ?? '—')}</div>
          <div className="stat-label">Subscription · {plan.name ?? plan.code ?? 'Pro'}</div>
        </div>
        <div className="console-card console-stat">
          <div className="stat-value">{data.outlets.length}</div>
          <div className="stat-label">Outlets</div>
        </div>
        <div className="console-card console-stat">
          <div className="stat-value">{data.staff.length}</div>
          <div className="stat-label">Staff</div>
        </div>
        <div className="console-card console-stat">
          <div className="stat-value">{fmtDate(end)}</div>
          <div className="stat-label">Period / trial ends</div>
        </div>
      </div>

      <div className="console-grid">
        <div className="console-card">
          <div className="console-row" style={{ justifyContent: 'space-between' }}>
            <h3 className="console-section-title">Outlets</h3>
            <button className="console-btn console-btn-ghost console-btn-sm" onClick={() => setShowNewOutlet((v) => !v)}>
              + Add outlet
            </button>
          </div>
          {showNewOutlet && (
            <div className="console-form console-row" style={{ marginBottom: 12 }}>
              <input className="console-input grow" placeholder="Outlet name" value={outletForm.name}
                onChange={(e) => setOutletForm((f) => ({ ...f, name: e.target.value }))} />
              <input className="console-input grow" placeholder="Terminal (e.g. POS-1)" value={outletForm.terminal}
                onChange={(e) => setOutletForm((f) => ({ ...f, terminal: e.target.value }))} />
              <button className="console-btn console-btn-primary console-btn-sm" disabled={busy}
                onClick={() => run(() => api.createOutlet({ name: outletForm.name, terminal: outletForm.terminal }), 'Outlet added')}>
                Add
              </button>
            </div>
          )}
          <div className="console-list">
            {data.outlets.map((o: any) => (
              <div className="console-item" key={o.id}>
                <div>
                  <div className="item-main">{o.name}</div>
                  <div className="item-sub">{o.terminal} · {o.address || '—'}</div>
                </div>
                <span className="console-badge badge-ok">{o.is_online ? 'online' : 'offline'}</span>
              </div>
            ))}
          </div>
        </div>

        <div className="console-card">
          <h3 className="console-section-title">Staff (PIN login)</h3>
          <div className="console-form console-row" style={{ marginBottom: 12 }}>
            <input className="console-input grow" placeholder="Name" value={staffForm.name}
              onChange={(e) => setStaffForm((f) => ({ ...f, name: e.target.value }))} />
            <select className="console-input" style={{ width: 150 }} value={staffForm.role}
              onChange={(e) => setStaffForm((f) => ({ ...f, role: e.target.value }))}>
              {['admin', 'manager', 'cashier', 'waiter', 'kitchen'].map((r) => <option key={r} value={r}>{r}</option>)}
            </select>
            <input className="console-input" style={{ width: 110 }} placeholder="PIN 4-6" maxLength={6} value={staffForm.pin}
              onChange={(e) => setStaffForm((f) => ({ ...f, pin: e.target.value }))} />
            <select className="console-input" style={{ width: 160 }} value={staffForm.outlet_id}
              onChange={(e) => setStaffForm((f) => ({ ...f, outlet_id: e.target.value }))}>
              <option value="">Whole organization</option>
              {data.outlets.map((o: any) => <option key={o.id} value={o.id}>{o.name}</option>)}
            </select>
            <button className="console-btn console-btn-primary console-btn-sm" disabled={busy || !staffForm.name || staffForm.pin.length < 4}
              onClick={() => run(() => api.createStaff({
                name: staffForm.name, role: staffForm.role, pin: staffForm.pin,
                outlet_id: staffForm.outlet_id || undefined,
              }), 'Staff added')}>
              Add
            </button>
          </div>
          <div className="console-list">
            {data.staff.map((s: any) => (
              <div className="console-item" key={s.id}>
                <div>
                  <div className="item-main">{s.name}</div>
                  <div className="item-sub">{s.role}{s.outlet_id ? ' · outlet-bound' : ' · org-wide'}</div>
                </div>
                <span className={`console-badge ${s.is_active ? 'badge-active' : 'badge-suspended'}`}>{s.is_active ? 'active' : 'inactive'}</span>
              </div>
            ))}
          </div>
        </div>

        <div className="console-card">
          <div className="console-row" style={{ justifyContent: 'space-between' }}>
            <h3 className="console-section-title">Invoices</h3>
            <button className="console-btn console-btn-ghost console-btn-sm" disabled={busy}
              onClick={() => run(api.rotateCode, 'Organization code rotated')}>Rotate org code</button>
          </div>
          <div className="console-list">
            {data.invoices.length === 0 && <p style={{ color: '#78716c', fontSize: 13 }}>No invoices yet — payments activate your plan.</p>}
            {data.invoices.map((inv: any) => (
              <div className="console-item" key={inv.id}>
                <div>
                  <div className="item-main">{inv.invoice_no}</div>
                  <div className="item-sub">{fmtDate(inv.paid_at)} · {inv.method} · {fmtRs(inv.gross_paise ?? inv.amount_paise)}</div>
                </div>
                <button className="console-btn console-btn-ghost console-btn-sm"
                  onClick={() => downloadInvoicePdf(inv.id, 'owner').catch((e) => setError(errMessage(e)))}>
                  PDF
                </button>
              </div>
            ))}
          </div>
        </div>

        {sub.cancel_at_period_end !== true && (
          <div className="console-card">
            <h3 className="console-section-title">Subscription</h3>
            <p style={{ fontSize: 13, color: '#4a443e' }}>
              Renewals are handled by the FoodPOS team after payment (bank/UPI). Need to stop? You can request cancellation.
            </p>
            <button className="console-btn console-btn-danger console-btn-sm" disabled={busy}
              onClick={() => { if (confirm('Stop renewing after the current period?')) run(api.cancelSubscription, 'Cancellation requested — renewals stop after this period'); }}>
              Cancel at period end
            </button>
          </div>
        )}
      </div>
    </div>
  );
};

// ================= Superadmin panel =================
const SuperAdminPanel: React.FC = () => {
  const [orgs, setOrgs] = useState<any[]>([]);
  const [stats, setStats] = useState<Record<string, any> | null>(null);
  const [status, setStatus] = useState('');
  const [error, setError] = useState('');
  const [detail, setDetail] = useState<Record<string, any> | null>(null);
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    try {
      setError('');
      const [orgData, statData] = await Promise.all([api.adminOrgs(status || undefined), api.adminStats()]);
      const list = (orgData.organizations ?? []) as any[];
      setOrgs(list);
      setStats(statData);
    } catch (e) {
      setError(errMessage(e));
    }
  }, [status]);

  useEffect(() => {
    load();
  }, [load]);

  const openDetail = async (id: string) => {
    try {
      setDetail(await api.adminOrgDetail(id));
    } catch (e) {
      setError(errMessage(e));
    }
  };

  const act = async (fn: () => Promise<any>, ok: string) => {
    setBusy(true);
    setError('');
    try {
      await fn();
      alert(ok);
      if (detail) openDetail(detail.org.id);
      await load();
    } catch (e) {
      setError(errMessage(e));
    } finally {
      setBusy(false);
    }
  };

  return (
    <div>
      <h1 className="console-title">Platform Overview</h1>
      <p className="console-subtitle">Superadmin — manage organizations and subscriptions.</p>
      {error && <div className="console-banner console-banner-error">{error}</div>}
      {stats && (
        <div className="console-cards" style={{ marginBottom: 18 }}>
          <div className="console-card console-stat"><div className="stat-value">{stats.total_orgs}</div><div className="stat-label">Organizations</div></div>
          <div className="console-card console-stat"><div className="stat-value">{stats.invoices}</div><div className="stat-label">Invoices</div></div>
          <div className="console-card console-stat"><div className="stat-value">{fmtRs(Number(stats.revenue_30d ?? 0))}</div><div className="stat-label">Revenue (30d)</div></div>
        </div>
      )}
      <div className="console-card">
        <div className="console-row" style={{ justifyContent: 'space-between', marginBottom: 12 }}>
          <h3 className="console-section-title" style={{ margin: 0 }}>Organizations</h3>
          <select className="console-select" style={{ width: 180 }} value={status} onChange={(e) => setStatus(e.target.value)}>
            <option value="">All statuses</option>
            {['trial', 'active', 'past_due', 'suspended', 'expired', 'closed'].map((s) => <option key={s} value={s}>{s}</option>)}
          </select>
        </div>
        <div className="console-list">
          {orgs.map((row: any) => {
            const o = row.organization ?? row;
            const s = row.subscription;
            return (
              <div className="console-item" key={o.id}>
                <div>
                  <div className="item-main">{o.name}</div>
                  <div className="item-sub">{o.id} · {o.email} · plan {s?.plan_id ?? '—'}</div>
                </div>
                <div className="console-row">
                  <span className={`console-badge badge-${o.status}`}>{o.status}</span>
                  <button className="console-btn console-btn-ghost console-btn-sm" onClick={() => openDetail(o.id)}>Manage</button>
                </div>
              </div>
            );
          })}
          {orgs.length === 0 && <p style={{ color: '#78716c', fontSize: 13 }}>No organizations found.</p>}
        </div>
      </div>

      {detail && <OrgDetailDialog detail={detail} busy={busy} act={act} onClose={() => setDetail(null)} />}
    </div>
  );
};

const OrgDetailDialog: React.FC<{ detail: Record<string, any>; busy: boolean; act: (fn: () => Promise<any>, ok: string) => void; onClose: () => void }> = ({ detail, busy, act, onClose }) => {
  const org = detail.org ?? {};
  const sub = detail.subscription ?? {};
  const invoices: any[] = detail.invoices ?? [];
  const [mode, setMode] = useState<'activate' | 'extend' | null>(null);
  const [form, setForm] = useState({ method: 'bank', period_days: '30', amount_paise: '', reference: '', notes: '' });

  return (
    <div className="console-dialog-overlay" onClick={onClose}>
      <div className="console-dialog" onClick={(e) => e.stopPropagation()}>
        <h3>{org.name}</h3>
        <p style={{ margin: '0 0 12px', color: '#78716c', fontSize: 13 }}>{org.id} · {org.email} · status <span className={`console-badge badge-${org.status}`}>{org.status}</span></p>
        <p style={{ fontSize: 13, margin: '0 0 14px' }}>
          Subscription: <b>{sub.status}</b> · plan {sub.plan_id} · {fmtDate(sub.current_period_end || sub.trial_ends_at)} ends · cancel_at_period_end: {sub.cancel_at_period_end ? 'yes' : 'no'}
        </p>
        {invoices.length > 0 && (
          <div style={{ marginBottom: 14 }}>
            <div style={{ fontSize: 12, color: '#78716c', marginBottom: 6 }}>Invoices</div>
            {invoices.map((inv: any) => (
              <div className="console-item" key={inv.id} style={{ padding: '8px 10px' }}>
                <div className="item-sub">{inv.invoice_no} · {fmtRs(inv.gross_paise ?? inv.amount_paise)}</div>
                <button className="console-btn console-btn-ghost console-btn-sm" onClick={() => downloadInvoicePdf(inv.id, 'admin')}>PDF</button>
              </div>
            ))}
          </div>
        )}
        {mode === 'activate' && (
          <div className="console-form" style={{ marginBottom: 14 }}>
            <div className="console-row">
              <select className="console-select" style={{ width: 140 }} value={form.method}
                onChange={(e) => setForm((f) => ({ ...f, method: e.target.value }))}>
                {['bank', 'upi', 'razorpay'].map((m) => <option key={m} value={m}>{m}</option>)}
              </select>
              <input className="console-input" style={{ width: 110 }} type="number" min={1} placeholder="Days" value={form.period_days}
                onChange={(e) => setForm((f) => ({ ...f, period_days: e.target.value }))} />
              <input className="console-input" style={{ width: 140 }} type="number" placeholder="Paise (0 = plan)" value={form.amount_paise}
                onChange={(e) => setForm((f) => ({ ...f, amount_paise: e.target.value }))} />
              <input className="console-input" placeholder="Reference (e.g. NEFT TXN)" value={form.reference}
                onChange={(e) => setForm((f) => ({ ...f, reference: e.target.value }))} />
            </div>
            <input className="console-input" placeholder="Notes" value={form.notes}
              onChange={(e) => setForm((f) => ({ ...f, notes: e.target.value }))} />
            <button className="console-btn console-btn-primary" disabled={busy}
              onClick={() => act(() => api.adminActivate(org.id, {
                method: form.method,
                period_days: Number(form.period_days) || undefined,
                amount_paise: form.amount_paise ? Number(form.amount_paise) : undefined,
                reference: form.reference || undefined,
                notes: form.notes || undefined,
              }), 'Activated + invoice created')}>
              Activate / renew
            </button>
          </div>
        )}
        {mode === 'extend' && (
          <div className="console-form" style={{ marginBottom: 14 }}>
            <div className="console-row">
              <input className="console-input" style={{ width: 130 }} type="number" min={1} placeholder="Days" value={form.period_days}
                onChange={(e) => setForm((f) => ({ ...f, period_days: e.target.value }))} />
              <button className="console-btn console-btn-primary" disabled={busy}
                onClick={() => act(() => api.adminExtend(org.id, Number(form.period_days) || 30, form.notes || undefined), 'Extended')}>
                Extend
              </button>
            </div>
          </div>
        )}
        <div className="console-row">
          <button className="console-btn console-btn-primary" onClick={() => setMode(mode === 'activate' ? null : 'activate')}>
            {mode === 'activate' ? 'Close payment form' : 'Activate / renew'}
          </button>
          <button className="console-btn console-btn-ghost" onClick={() => setMode(mode === 'extend' ? null : 'extend')}>
            {mode === 'extend' ? 'Close extend form' : 'Extend'}
          </button>
          <button className="console-btn console-btn-danger" disabled={busy}
            onClick={() => { if (confirm(`Suspend ${org.name}? Paid writes stop immediately.`)) act(() => api.adminSuspend(org.id, 'suspended from console'), 'Suspended'); }}>
            Suspend
          </button>
          <button className="console-btn console-btn-danger" disabled={busy}
            onClick={() => { if (confirm(`Cancel ${org.name} permanently?`)) act(() => api.adminCancel(org.id, 'cancelled from console'), 'Cancelled'); }}>
            Cancel
          </button>
          <button className="console-btn console-btn-ghost" onClick={onClose}>Close</button>
        </div>
      </div>
    </div>
  );
};
