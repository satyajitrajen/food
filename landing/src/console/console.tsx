import React, { useCallback, useEffect, useState } from 'react';
import { useRouter } from '../router';
import { PLAN } from '../data/plan';
import {
  ApiError,
  ConsoleSession,
  api,
  clearSession,
  downloadInvoicePdf,
  forgotPassword,
  loadSession,
  loginAdmin,
  loginOwner,
  registerOrg,
  resetPassword,
  saveSession,
  startAutoRenew,
  verifyEmail,
} from './api';
import { ConsoleDialog, CopyField, DialogProvider, useDialogs } from './dialog';

// ---- helpers ----
function fmtInr(paise: number): string {
  return `₹${(paise / 100).toLocaleString('en-IN', { maximumFractionDigits: 2 })}`;
}
function fmtDate(v: string | null | undefined): string {
  if (!v) return '—';
  const d = new Date(v);
  return isNaN(d.getTime()) ? '—' : d.toLocaleDateString('en-IN', { day: '2-digit', month: 'short', year: 'numeric' });
}
function errMessage(e: unknown): string {
  return e instanceof ApiError ? e.message : e instanceof Error ? e.message : 'Something went wrong';
}
function capitalise(v: string): string {
  return v ? v.charAt(0).toUpperCase() + v.slice(1) : v;
}

// Human labels for raw backend values.
const STATUS_LABELS: Record<string, string> = {
  trial: 'Free trial',
  active: 'Active',
  past_due: 'Payment due',
  suspended: 'Suspended',
  expired: 'Expired',
  closed: 'Closed',
  cancelled: 'Cancelled',
};
function statusLabel(s: string | null | undefined): string {
  if (!s) return '—';
  return STATUS_LABELS[s] ?? capitalise(s.replace(/_/g, ' '));
}

// Plan ids are "plan-<code>" (store/saas.go SeedDefaultPlans).
const PLAN_NAMES: Record<string, string> = {
  [PLAN.code]: PLAN.name,
  [`plan-${PLAN.code}`]: PLAN.name,
};
function planName(sub: Record<string, any> | null | undefined): string {
  if (!sub) return '—';
  if (sub.plan?.name) return String(sub.plan.name);
  const id = String(sub.plan_id ?? '');
  return PLAN_NAMES[id] ?? (id ? capitalise(id.replace(/^plan-/, '')) : '—');
}

const STAFF_ROLES = ['admin', 'manager', 'cashier', 'waiter', 'kitchen'] as const;
const OUTLET_BOUND_ROLES = new Set(['waiter', 'kitchen']);

// Reads a query parameter from the router path (hash routing keeps the query
// in the path) or from the real URL (history routing / direct e-mail links).
function queryParam(currentPath: string, key: string): string {
  const q = currentPath.includes('?') ? currentPath.slice(currentPath.indexOf('?')) : '';
  return new URLSearchParams(q).get(key) ?? new URLSearchParams(window.location.search).get(key) ?? '';
}

// loadRazorpayScript injects checkout.js once per page load.
function loadRazorpayScript(): Promise<void> {
  const w = window as unknown as { Razorpay?: unknown };
  if (w.Razorpay) return Promise.resolve();
  return new Promise((resolve, reject) => {
    const s = document.createElement('script');
    s.src = 'https://checkout.razorpay.com/v1/checkout.js';
    s.onload = () => resolve();
    s.onerror = () => reject(new Error('Could not load Razorpay checkout'));
    document.head.appendChild(s);
  });
}

// ================= Console root / layout =================
export const ConsoleApp: React.FC = () => (
  <DialogProvider>
    <ConsoleRoutes />
  </DialogProvider>
);

const ConsoleRoutes: React.FC = () => {
  const { currentPath, navigate } = useRouter();
  const [session, setSession] = useState<ConsoleSession | null>(() => loadSession());

  useEffect(() => {
    setSession(loadSession());
  }, [currentPath]);

  // E-mail links may land on /reset or /verify (no /console prefix).
  const routePath = currentPath.split('?')[0].replace(/^\/(reset|verify)$/, '/console/$1');
  switch (routePath) {
    case '/console/login':
      return <LoginPage />;
    case '/console/register':
      return <RegisterPage />;
    case '/console/forgot':
      return <ForgotPasswordPage />;
    case '/console/reset':
      return <ResetPasswordPage />;
    case '/console/verify':
      return <VerifyEmailPage />;
  }
  if (!session) {
    return <RedirectToLogin />;
  }
  return (
    <Layout
      session={session}
      onLogout={() => {
        clearSession();
        navigate('/console/login');
      }}
    />
  );
};

const RedirectToLogin: React.FC = () => {
  const { navigate } = useRouter();
  useEffect(() => navigate('/console/login'), [navigate]);
  return null;
};

const BrandMark: React.FC = () => (
  <span className="console-brand-mark" aria-hidden="true">H</span>
);

const Layout: React.FC<{ session: ConsoleSession; onLogout: () => void }> = ({ session, onLogout }) => {
  const { navigate } = useRouter();
  return (
    <div className="console-root">
      <header className="console-topbar">
        <div className="console-brand">
          <BrandMark />
          Hishobkr Console
        </div>
        <div className="console-user">
          <span className="console-user-name">{session.name}</span>
          <span className="console-badge badge-role">{session.role === 'admin' ? 'Superadmin' : 'Owner'}</span>
          <button className="console-btn console-btn-ghost console-btn-sm" onClick={() => navigate('/')}>Website</button>
          <button className="console-btn console-btn-danger console-btn-sm" onClick={onLogout}>Log out</button>
        </div>
      </header>
      <main className="console-main">
        {session.role === 'admin' ? <SuperAdminPanel /> : <OwnerPanel />}
      </main>
    </div>
  );
};

// Shared shell for the signed-out pages.
const AuthCard: React.FC<{ title: string; hint?: React.ReactNode; children: React.ReactNode }> = ({ title, hint, children }) => (
  <div className="console-login-wrap">
    <main className="console-login-card">
      <div className="console-brand console-brand-dark">
        <BrandMark />
        Hishobkr Console
      </div>
      <h1 className="console-auth-title">{title}</h1>
      {hint && <p className="hint">{hint}</p>}
      {children}
    </main>
  </div>
);

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
    <AuthCard title="Sign in" hint="Manage your restaurant, outlets, staff, and subscription.">
      <div className="console-tabs" role="group" aria-label="Account type">
        <button type="button" aria-pressed={mode === 'owner'} className={mode === 'owner' ? 'active' : ''} onClick={() => setMode('owner')}>Restaurant Owner</button>
        <button type="button" aria-pressed={mode === 'admin'} className={mode === 'admin' ? 'active' : ''} onClick={() => setMode('admin')}>Superadmin</button>
      </div>
      {error && <div className="console-banner console-banner-error" role="alert">{error}</div>}
      <form className="console-form" onSubmit={submit}>
        <div className="console-field">
          <label htmlFor="login-email">E-mail</label>
          <input id="login-email" className="console-input" type="email" required autoComplete="email" value={email}
            onChange={(e) => setEmail(e.target.value)} />
        </div>
        <div className="console-field">
          <div className="console-label-row">
            <label htmlFor="login-password">Password</label>
            {mode === 'owner' && (
              <button type="button" className="console-link" onClick={() => navigate('/console/forgot')}>
                Forgot password?
              </button>
            )}
          </div>
          <input id="login-password" className="console-input" type="password" required autoComplete="current-password" value={password}
            onChange={(e) => setPassword(e.target.value)} />
        </div>
        <button className="console-btn console-btn-primary console-btn-block" disabled={busy}>
          {busy ? 'Signing in…' : 'Sign in'}
        </button>
      </form>
      {mode === 'owner' && (
        <p className="console-auth-foot">
          New here?{' '}
          <button type="button" className="console-link" onClick={() => navigate(`/console/register?plan=${PLAN.code}`)}>
            Start a {PLAN.trialDays}-day free trial
          </button>
        </p>
      )}
    </AuthCard>
  );
};

// ================= Forgot / reset / verify =================
const ForgotPasswordPage: React.FC = () => {
  const { navigate } = useRouter();
  const [email, setEmail] = useState('');
  const [error, setError] = useState('');
  const [sent, setSent] = useState(false);
  const [busy, setBusy] = useState(false);

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    setBusy(true);
    setError('');
    try {
      await forgotPassword(email.trim());
      setSent(true);
    } catch (err) {
      setError(errMessage(err));
    } finally {
      setBusy(false);
    }
  };

  return (
    <AuthCard title="Reset your password" hint={sent ? undefined : 'Enter the e-mail you registered with and we will send you a reset link.'}>
      {sent ? (
        <div className="console-banner console-banner-ok" role="status">
          If an account exists for <strong>{email.trim()}</strong>, we&apos;ve emailed a link to reset your password. The link expires, so use it soon.
        </div>
      ) : (
        <>
          {error && <div className="console-banner console-banner-error" role="alert">{error}</div>}
          <form className="console-form" onSubmit={submit}>
            <div className="console-field">
              <label htmlFor="forgot-email">E-mail</label>
              <input id="forgot-email" className="console-input" type="email" required autoComplete="email" value={email}
                onChange={(e) => setEmail(e.target.value)} />
            </div>
            <button className="console-btn console-btn-primary console-btn-block" disabled={busy}>
              {busy ? 'Sending…' : 'Send reset link'}
            </button>
          </form>
        </>
      )}
      <p className="console-auth-foot">
        <button type="button" className="console-link" onClick={() => navigate('/console/login')}>Back to sign in</button>
      </p>
    </AuthCard>
  );
};

const ResetPasswordPage: React.FC = () => {
  const { currentPath, navigate } = useRouter();
  const token = queryParam(currentPath, 'token');
  const [password, setPassword] = useState('');
  const [confirmPw, setConfirmPw] = useState('');
  const [error, setError] = useState('');
  const [done, setDone] = useState(false);
  const [busy, setBusy] = useState(false);

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (password !== confirmPw) {
      setError('The two passwords do not match.');
      return;
    }
    setBusy(true);
    setError('');
    try {
      await resetPassword(token, password);
      clearSession();
      setDone(true);
    } catch (err) {
      setError(errMessage(err));
    } finally {
      setBusy(false);
    }
  };

  return (
    <AuthCard title="Choose a new password">
      {!token ? (
        <div className="console-banner console-banner-error" role="alert">
          This reset link is incomplete. Request a new one from the sign-in page.
        </div>
      ) : done ? (
        <div className="console-banner console-banner-ok" role="status">
          Your password has been changed and you have been signed out of other sessions. Sign in with your new password.
        </div>
      ) : (
        <>
          {error && <div className="console-banner console-banner-error" role="alert">{error}</div>}
          <form className="console-form" onSubmit={submit}>
            <div className="console-field">
              <label htmlFor="reset-password">New password</label>
              <input id="reset-password" className="console-input" type="password" required minLength={8} autoComplete="new-password"
                aria-describedby="reset-password-hint" value={password} onChange={(e) => setPassword(e.target.value)} />
              <span id="reset-password-hint" className="console-help">At least 8 characters.</span>
            </div>
            <div className="console-field">
              <label htmlFor="reset-confirm">Confirm new password</label>
              <input id="reset-confirm" className="console-input" type="password" required minLength={8} autoComplete="new-password"
                value={confirmPw} onChange={(e) => setConfirmPw(e.target.value)} />
            </div>
            <button className="console-btn console-btn-primary console-btn-block" disabled={busy}>
              {busy ? 'Saving…' : 'Set new password'}
            </button>
          </form>
        </>
      )}
      <p className="console-auth-foot">
        {(!token || done || error) && (
          <button type="button" className="console-link" onClick={() => navigate(done ? '/console/login' : '/console/forgot')}>
            {done ? 'Go to sign in' : 'Request a new link'}
          </button>
        )}
      </p>
    </AuthCard>
  );
};

const VerifyEmailPage: React.FC = () => {
  const { currentPath, navigate } = useRouter();
  const token = queryParam(currentPath, 'token');
  const [state, setState] = useState<'working' | 'ok' | 'error'>(token ? 'working' : 'error');
  const [error, setError] = useState(token ? '' : 'This verification link is incomplete.');

  useEffect(() => {
    if (!token) return;
    let cancelled = false;
    verifyEmail(token)
      .then(() => !cancelled && setState('ok'))
      .catch((err) => {
        if (cancelled) return;
        setError(errMessage(err));
        setState('error');
      });
    return () => {
      cancelled = true;
    };
  }, [token]);

  const signedIn = !!loadSession();

  return (
    <AuthCard title="Verify your e-mail">
      {state === 'working' && <p role="status">Verifying…</p>}
      {state === 'ok' && (
        <div className="console-banner console-banner-ok" role="status">Your e-mail address is verified. Thank you!</div>
      )}
      {state === 'error' && (
        <div className="console-banner console-banner-error" role="alert">
          {error || 'This link is invalid or has expired.'}
        </div>
      )}
      <button type="button" className="console-btn console-btn-primary console-btn-block"
        onClick={() => navigate(signedIn ? '/console' : '/console/login')}>
        {signedIn ? 'Open my dashboard' : 'Go to sign in'}
      </button>
    </AuthCard>
  );
};

// ================= Registration =================
const RegisterPage: React.FC = () => {
  const { navigate } = useRouter();
  // Single plan today: any ?plan= value registers on it (the backend rejects
  // unknown codes, so never forward an arbitrary query value).
  const [form, setForm] = useState({ org_name: '', owner_name: '', email: '', phone: '', password: '', outlet_name: '', gstin: '', plan_code: PLAN.code as string });
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
      <AuthCard title="Welcome to Hishobkr" hint={`Your ${PLAN.trialDays}-day free trial is live. Save these now:`}>
        <div className="console-form">
          <CopyField label="Organization code (for app setup)" value={String(info.org_code ?? '')} />
          <CopyField label="Initial POS admin PIN (shown only once)" value={String(info.admin_pin ?? '')} />
          <div className="console-banner console-banner-info">
            On your device, open the Hishobkr app and enter the organization code above, then sign in with the admin PIN.
          </div>
          <button className="console-btn console-btn-primary console-btn-block" onClick={() => navigate('/console')}>
            Open my dashboard
          </button>
        </div>
      </AuthCard>
    );
  }

  return (
    <AuthCard
      title="Create your account"
      hint={<>One outlet is created for you; add up to {PLAN.maxOutlets} from your dashboard.</>}
    >
      <p className="console-plan-pill">
        {PLAN.name} · {PLAN.priceLabel}/{PLAN.period} · {PLAN.trialDays}-day free trial
      </p>
      {error && <div className="console-banner console-banner-error" role="alert">{error}</div>}
      <form className="console-form" onSubmit={submit}>
        <div className="console-field">
          <label htmlFor="reg-org">Restaurant name</label>
          <input id="reg-org" className="console-input" required autoComplete="organization" value={form.org_name} onChange={set('org_name')} />
        </div>
        <div className="console-field">
          <label htmlFor="reg-owner">Your name</label>
          <input id="reg-owner" className="console-input" required autoComplete="name" value={form.owner_name} onChange={set('owner_name')} />
        </div>
        <div className="console-field">
          <label htmlFor="reg-email">E-mail</label>
          <input id="reg-email" className="console-input" required type="email" autoComplete="email" value={form.email} onChange={set('email')} />
        </div>
        <div className="console-field">
          <label htmlFor="reg-phone">Mobile number <span className="console-optional">(optional)</span></label>
          <input id="reg-phone" className="console-input" type="tel" autoComplete="tel" inputMode="tel"
            pattern="[+]?[0-9 \-]{7,20}" placeholder="e.g. 98765 43210" value={form.phone} onChange={set('phone')} />
        </div>
        <div className="console-field">
          <label htmlFor="reg-password">Password</label>
          <input id="reg-password" className="console-input" required type="password" minLength={8} autoComplete="new-password"
            aria-describedby="reg-password-hint" value={form.password} onChange={set('password')} />
          <span id="reg-password-hint" className="console-help">At least 8 characters.</span>
        </div>
        <div className="console-field">
          <label htmlFor="reg-outlet">First outlet name</label>
          <input id="reg-outlet" className="console-input" required placeholder="e.g. Baner" value={form.outlet_name} onChange={set('outlet_name')} />
        </div>
        <div className="console-field">
          <label htmlFor="reg-gstin">GSTIN <span className="console-optional">(optional)</span></label>
          <input id="reg-gstin" className="console-input" autoCapitalize="characters" maxLength={15} value={form.gstin} onChange={set('gstin')} />
        </div>
        <button className="console-btn console-btn-primary console-btn-block" disabled={busy}>
          {busy ? 'Creating…' : `Start ${PLAN.trialDays}-day free trial`}
        </button>
      </form>
      <p className="console-auth-foot">
        Already have an account?{' '}
        <button type="button" className="console-link" onClick={() => navigate('/console/login')}>Sign in</button>
      </p>
    </AuthCard>
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

const LimitStat: React.FC<{ used: number; max?: number; label: string }> = ({ used, max, label }) => {
  const hasMax = typeof max === 'number' && max > 0;
  const full = hasMax && used >= (max as number);
  return (
    <div className="console-card console-stat">
      <div className="stat-value">
        {used}
        {hasMax && <span className="stat-max"> / {max}</span>}
      </div>
      <div className="stat-label">{label}{full ? ' · plan limit reached' : ''}</div>
      {hasMax && (
        <div className="console-meter" aria-hidden="true">
          <span style={{ width: `${Math.min(100, (used / (max as number)) * 100)}%` }} className={full ? 'is-full' : ''} />
        </div>
      )}
    </div>
  );
};

const OwnerPanel: React.FC = () => {
  const { confirm, notify } = useDialogs();
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
        {error && <div className="console-banner console-banner-error" role="alert">{error}</div>}
        <p>Loading…</p>
      </div>
    );
  }

  const org = data.org;
  const sub = data.subscription || {};
  const plan = sub.plan || {};
  const end = sub.status === 'trial' ? sub.trial_ends_at : sub.current_period_end || sub.trial_ends_at;
  const maxOutlets: number | undefined = typeof plan.max_outlets === 'number' ? plan.max_outlets : undefined;
  const maxStaff: number | undefined = typeof plan.max_staff === 'number' ? plan.max_staff : undefined;
  const outletsFull = maxOutlets !== undefined && data.outlets.length >= maxOutlets;
  const staffFull = maxStaff !== undefined && data.staff.length >= maxStaff;
  const staffNeedsOutlet = OUTLET_BOUND_ROLES.has(staffForm.role) && !staffForm.outlet_id;
  const pinValid = /^\d{4,6}$/.test(staffForm.pin);
  const autoPayOn = sub.gateway_status === 'active' || sub.gateway_status === 'authenticated';

  const run = async (fn: () => Promise<any>, okMsg: string): Promise<boolean> => {
    setBusy(true);
    setError('');
    setNotice('');
    try {
      await fn();
      setNotice(okMsg);
      await load();
      return true;
    } catch (e) {
      setError(errMessage(e));
      return false;
    } finally {
      setBusy(false);
    }
  };

  const addOutlet = async (e: React.FormEvent) => {
    e.preventDefault();
    const ok = await run(() => api.createOutlet({ name: outletForm.name.trim(), terminal: outletForm.terminal.trim() }), 'Outlet added');
    if (ok) {
      setOutletForm({ name: '', terminal: '' });
      setShowNewOutlet(false);
    }
  };

  const addStaff = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!pinValid || staffNeedsOutlet) return;
    const ok = await run(() => api.createStaff({
      name: staffForm.name.trim(), role: staffForm.role, pin: staffForm.pin,
      outlet_id: staffForm.outlet_id || undefined,
    }), 'Staff member added');
    if (ok) setStaffForm((f) => ({ ...f, name: '', pin: '' }));
  };

  const rotateCode = async () => {
    const yes = await confirm({
      title: 'Rotate organization code?',
      message: 'Devices that are not yet set up will need the new code. Devices already signed in keep working.',
      confirmLabel: 'Rotate code',
    });
    if (!yes) return;
    setBusy(true);
    setError('');
    setNotice('');
    try {
      const res = await api.rotateCode();
      await notify({
        title: 'New organization code',
        message: <CopyField label="Organization code" value={String(res?.org_code ?? '')} />,
      });
    } catch (e) {
      setError(errMessage(e));
    } finally {
      setBusy(false);
    }
  };

  const cancelAtPeriodEnd = async () => {
    const yes = await confirm({
      title: 'Cancel at period end?',
      message: `Renewals stop after ${fmtDate(end)}. You keep full access until then.`,
      confirmLabel: 'Cancel renewal',
      cancelLabel: 'Keep subscription',
      danger: true,
    });
    if (yes) run(api.cancelSubscription, 'Cancellation requested — renewals stop after this period');
  };

  const openAutoRenewCheckout = async () => {
    setBusy(true);
    setError('');
    setNotice('');
    try {
      const start = await startAutoRenew();
      await loadRazorpayScript();
      const w = window as unknown as {
        Razorpay?: new (opts: Record<string, unknown>) => { open: () => void };
      };
      if (!w.Razorpay) throw new Error('Could not load Razorpay checkout');
      const session = loadSession();
      const rzp = new w.Razorpay({
        key: start.key_id,
        subscription_id: start.subscription_id,
        name: 'Hishobkr',
        description: `${start.plan_name} · auto-renew`,
        prefill: session ? { email: session.email } : undefined,
        theme: { color: '#067A37' },
        modal: { ondismiss: () => setNotice('Checkout closed — no charge was made') },
      });
      rzp.open();
      setNotice('Complete the payment in the Razorpay window to enable auto-renew');
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
      <p className="console-subtitle">{org.name}</p>
      {error && <div className="console-banner console-banner-error" role="alert">{error}</div>}
      {notice && <div className="console-banner console-banner-ok" role="status">{notice}</div>}

      <div className="console-cards" style={{ marginBottom: 18 }}>
        <div className="console-card console-stat">
          <div className="stat-value stat-value-text">{statusLabel(sub.status)}</div>
          <div className="stat-label">{planName(sub)}</div>
        </div>
        <LimitStat used={data.outlets.length} max={maxOutlets} label="Outlets" />
        <LimitStat used={data.staff.length} max={maxStaff} label="Staff" />
        <div className="console-card console-stat">
          <div className="stat-value stat-value-text">{fmtDate(end)}</div>
          <div className="stat-label">{sub.status === 'trial' ? 'Trial ends' : sub.cancel_at_period_end ? 'Access ends' : 'Renews on'}</div>
        </div>
      </div>

      <div className="console-grid">
        <section className="console-card" aria-labelledby="outlets-title">
          <div className="console-row" style={{ justifyContent: 'space-between' }}>
            <h2 className="console-section-title" id="outlets-title">Outlets</h2>
            <button type="button" className="console-btn console-btn-ghost console-btn-sm" disabled={outletsFull}
              aria-expanded={showNewOutlet} aria-controls="new-outlet-form"
              onClick={() => setShowNewOutlet((v) => !v)}>
              {showNewOutlet ? 'Close' : '+ Add outlet'}
            </button>
          </div>
          {outletsFull && (
            <p className="console-help" style={{ marginBottom: 10 }}>
              Your plan includes up to {maxOutlets} outlets.
            </p>
          )}
          {showNewOutlet && !outletsFull && (
            <form id="new-outlet-form" className="console-form console-inline-form" onSubmit={addOutlet}>
              <div className="console-field grow">
                <label htmlFor="outlet-name">Outlet name</label>
                <input id="outlet-name" className="console-input" required value={outletForm.name}
                  onChange={(e) => setOutletForm((f) => ({ ...f, name: e.target.value }))} />
              </div>
              <div className="console-field grow">
                <label htmlFor="outlet-terminal">Counter name</label>
                <input id="outlet-terminal" className="console-input" placeholder="e.g. Main Counter" value={outletForm.terminal}
                  onChange={(e) => setOutletForm((f) => ({ ...f, terminal: e.target.value }))} />
              </div>
              <button className="console-btn console-btn-primary console-btn-sm" disabled={busy || !outletForm.name.trim()}>
                Add outlet
              </button>
            </form>
          )}
          <div className="console-list">
            {data.outlets.map((o: any) => (
              <div className="console-item" key={o.id}>
                <div>
                  <div className="item-main">{o.name}</div>
                  <div className="item-sub">{[o.terminal, o.address].filter(Boolean).join(' · ') || '—'}</div>
                </div>
                <span className={`console-badge ${o.is_online ? 'badge-online' : 'badge-offline'}`}>
                  {o.is_online ? 'Online' : 'Offline'}
                </span>
              </div>
            ))}
          </div>
        </section>

        <section className="console-card" aria-labelledby="staff-title">
          <h2 className="console-section-title" id="staff-title">Staff (PIN login)</h2>
          {staffFull ? (
            <p className="console-help" style={{ marginBottom: 10 }}>
              Your plan includes up to {maxStaff} staff members.
            </p>
          ) : (
            <form className="console-form console-inline-form" onSubmit={addStaff}>
              <div className="console-field grow">
                <label htmlFor="staff-name">Name</label>
                <input id="staff-name" className="console-input" required value={staffForm.name}
                  onChange={(e) => setStaffForm((f) => ({ ...f, name: e.target.value }))} />
              </div>
              <div className="console-field">
                <label htmlFor="staff-role">Role</label>
                <select id="staff-role" className="console-input" value={staffForm.role}
                  onChange={(e) => setStaffForm((f) => ({ ...f, role: e.target.value }))}>
                  {STAFF_ROLES.map((r) => <option key={r} value={r}>{capitalise(r)}</option>)}
                </select>
              </div>
              <div className="console-field">
                <label htmlFor="staff-pin">PIN (4–6 digits)</label>
                <input id="staff-pin" className="console-input console-input-pin" type="password" inputMode="numeric"
                  autoComplete="new-password" pattern="\d{4,6}" minLength={4} maxLength={6} required
                  title="4 to 6 digits" value={staffForm.pin}
                  onChange={(e) => setStaffForm((f) => ({ ...f, pin: e.target.value.replace(/\D/g, '') }))} />
              </div>
              <div className="console-field">
                <label htmlFor="staff-outlet">Outlet</label>
                <select id="staff-outlet" className="console-input" value={staffForm.outlet_id}
                  aria-describedby={staffNeedsOutlet ? 'staff-outlet-hint' : undefined}
                  aria-invalid={staffNeedsOutlet || undefined}
                  onChange={(e) => setStaffForm((f) => ({ ...f, outlet_id: e.target.value }))}>
                  <option value="">All outlets</option>
                  {data.outlets.map((o: any) => <option key={o.id} value={o.id}>{o.name}</option>)}
                </select>
              </div>
              <button className="console-btn console-btn-primary console-btn-sm"
                disabled={busy || !staffForm.name.trim() || !pinValid || staffNeedsOutlet}>
                Add staff
              </button>
              {staffNeedsOutlet && (
                <p id="staff-outlet-hint" className="console-help console-inline-hint">
                  {capitalise(staffForm.role)} staff must be assigned to a specific outlet.
                </p>
              )}
            </form>
          )}
          <div className="console-list">
            {data.staff.map((s: any) => (
              <div className="console-item" key={s.id}>
                <div>
                  <div className="item-main">{s.name}</div>
                  <div className="item-sub">
                    {capitalise(String(s.role ?? ''))} · {s.outlet_id
                      ? data.outlets.find((o: any) => o.id === s.outlet_id)?.name ?? 'One outlet'
                      : 'All outlets'}
                  </div>
                </div>
                <span className={`console-badge ${s.is_active ? 'badge-active' : 'badge-offline'}`}>{s.is_active ? 'Active' : 'Inactive'}</span>
              </div>
            ))}
          </div>
        </section>

        <section className="console-card" aria-labelledby="sub-title">
          <h2 className="console-section-title" id="sub-title">Subscription</h2>
          <div className="console-row" style={{ marginBottom: 10 }}>
            <span className={`console-badge badge-${sub.status ?? 'none'}`}>{statusLabel(sub.status)}</span>
            {sub.cancel_at_period_end && <span className="console-badge badge-past_due">Cancels at period end</span>}
            {autoPayOn && <span className="console-badge badge-active">Auto-renew on</span>}
          </div>
          {sub.cancel_at_period_end ? (
            <p className="console-text">
              Renewals are stopped. You keep full access until {fmtDate(end)}.
            </p>
          ) : sub.status === 'trial' ? (
            <p className="console-text">
              {autoPayOn
                ? `Free trial until ${fmtDate(sub.trial_ends_at)} — auto-pay is on, the first charge happens automatically.`
                : `Free trial until ${fmtDate(sub.trial_ends_at)}. Enable auto-pay now: the mandate is authorized today and the first charge happens automatically when the trial ends.`}
            </p>
          ) : (
            <p className="console-text">
              Auto-renew charges your plan each cycle via UPI or card. Cancel anytime; renewals stop after the current period.
            </p>
          )}
          {!sub.cancel_at_period_end && (
            <div className="console-row" style={{ gap: 8 }}>
              {sub.gateway_status !== 'active' && (
                <button className="console-btn console-btn-primary console-btn-sm" disabled={busy}
                  onClick={openAutoRenewCheckout}>
                  Enable auto-renew (UPI / Card)
                </button>
              )}
              <button className="console-btn console-btn-danger console-btn-sm" disabled={busy} onClick={cancelAtPeriodEnd}>
                Cancel at period end
              </button>
            </div>
          )}
        </section>

        <section className="console-card" aria-labelledby="inv-title">
          <h2 className="console-section-title" id="inv-title">Invoices</h2>
          <div className="console-list">
            {data.invoices.length === 0 && <p className="console-help">No invoices yet — your first invoice appears after the first payment.</p>}
            {data.invoices.map((inv: any) => (
              <div className="console-item" key={inv.id}>
                <div>
                  <div className="item-main">{inv.invoice_no}</div>
                  <div className="item-sub">{fmtDate(inv.paid_at)} · {capitalise(String(inv.method ?? ''))} · {fmtInr(inv.gross_paise ?? inv.amount_paise)}</div>
                </div>
                <button className="console-btn console-btn-ghost console-btn-sm"
                  aria-label={`Download invoice ${inv.invoice_no} as PDF`}
                  onClick={() => downloadInvoicePdf(inv.id, 'owner').catch((e) => setError(errMessage(e)))}>
                  PDF
                </button>
              </div>
            ))}
          </div>
        </section>

        <section className="console-card" aria-labelledby="settings-title">
          <h2 className="console-section-title" id="settings-title">Organization settings</h2>
          <div className="console-form">
            <CopyField label="Org ID (for support requests)" value={String(org.id ?? '')} />
            <div>
              <button type="button" className="console-btn console-btn-ghost console-btn-sm" disabled={busy} onClick={rotateCode}>
                Rotate organization code
              </button>
              <p className="console-help" style={{ marginTop: 6 }}>
                Issue a new code for setting up devices if the old one was shared too widely.
              </p>
            </div>
          </div>
        </section>
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
  const [notice, setNotice] = useState('');
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
    setNotice('');
    try {
      await fn();
      setNotice(ok);
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
      {error && <div className="console-banner console-banner-error" role="alert">{error}</div>}
      {notice && <div className="console-banner console-banner-ok" role="status">{notice}</div>}
      {stats && (
        <div className="console-cards" style={{ marginBottom: 18 }}>
          <div className="console-card console-stat"><div className="stat-value">{stats.total_orgs}</div><div className="stat-label">Organizations</div></div>
          <div className="console-card console-stat"><div className="stat-value">{stats.invoices}</div><div className="stat-label">Invoices</div></div>
          <div className="console-card console-stat"><div className="stat-value">{fmtInr(Number(stats.revenue_30d ?? 0))}</div><div className="stat-label">Revenue (30 days)</div></div>
        </div>
      )}
      <section className="console-card" aria-labelledby="orgs-title">
        <div className="console-row" style={{ justifyContent: 'space-between', marginBottom: 12 }}>
          <h2 className="console-section-title" id="orgs-title" style={{ margin: 0 }}>Organizations</h2>
          <div className="console-row">
            <label htmlFor="org-status-filter" className="console-label">Status</label>
            <select id="org-status-filter" className="console-select" style={{ width: 180 }} value={status} onChange={(e) => setStatus(e.target.value)}>
              <option value="">All statuses</option>
              {['trial', 'active', 'past_due', 'suspended', 'expired', 'closed'].map((s) => <option key={s} value={s}>{statusLabel(s)}</option>)}
            </select>
          </div>
        </div>
        <div className="console-list">
          {orgs.map((row: any) => {
            const o = row.organization ?? row;
            const s = row.subscription;
            return (
              <div className="console-item" key={o.id}>
                <div>
                  <div className="item-main">{o.name}</div>
                  <div className="item-sub">{o.email}{o.phone ? ` · ${o.phone}` : ''} · {planName(s)}</div>
                </div>
                <div className="console-row">
                  <span className={`console-badge badge-${o.status}`}>{statusLabel(o.status)}</span>
                  <button className="console-btn console-btn-ghost console-btn-sm" onClick={() => openDetail(o.id)}>Manage</button>
                </div>
              </div>
            );
          })}
          {orgs.length === 0 && <p className="console-help">No organizations found.</p>}
        </div>
      </section>

      {detail && <OrgDetailDialog detail={detail} busy={busy} act={act} onClose={() => setDetail(null)} />}
    </div>
  );
};

const OrgDetailDialog: React.FC<{ detail: Record<string, any>; busy: boolean; act: (fn: () => Promise<any>, ok: string) => void; onClose: () => void }> = ({ detail, busy, act, onClose }) => {
  const { confirm } = useDialogs();
  const org = detail.org ?? {};
  const sub = detail.subscription ?? {};
  const invoices: any[] = detail.invoices ?? [];
  const [mode, setMode] = useState<'activate' | 'extend' | null>(null);
  const [form, setForm] = useState({ method: 'bank', period_days: '', amount_rupees: '', reference: '', notes: '' });
  const [formError, setFormError] = useState('');

  const planPrice = typeof sub.plan?.price_paise === 'number' ? fmtInr(sub.plan.price_paise) : null;
  const planDays = typeof sub.plan?.interval_days === 'number' ? sub.plan.interval_days : null;

  const activate = (e: React.FormEvent) => {
    e.preventDefault();
    setFormError('');
    let amountPaise: number | undefined;
    if (form.amount_rupees.trim() !== '') {
      const rupees = Number(form.amount_rupees);
      if (!Number.isFinite(rupees) || rupees <= 0) {
        setFormError('Enter the amount received in rupees, or leave it blank to use the plan price.');
        return;
      }
      amountPaise = Math.round(rupees * 100);
    }
    act(() => api.adminActivate(org.id, {
      method: form.method,
      period_days: Number(form.period_days) || undefined,
      amount_paise: amountPaise,
      reference: form.reference || undefined,
      notes: form.notes || undefined,
    }), 'Activated and invoice created');
  };

  const extend = (e: React.FormEvent) => {
    e.preventDefault();
    act(() => api.adminExtend(org.id, Number(form.period_days) || 30, form.notes || undefined), 'Subscription extended');
  };

  const suspend = async () => {
    if (await confirm({
      title: `Suspend ${org.name}?`,
      message: 'Paid features stop working for this organization immediately.',
      confirmLabel: 'Suspend',
      danger: true,
    })) act(() => api.adminSuspend(org.id, 'suspended from console'), 'Organization suspended');
  };

  const cancelOrg = async () => {
    if (await confirm({
      title: `Cancel ${org.name} permanently?`,
      message: 'This closes the organization. It cannot be undone from the console.',
      confirmLabel: 'Cancel organization',
      cancelLabel: 'Keep',
      danger: true,
    })) act(() => api.adminCancel(org.id, 'cancelled from console'), 'Organization cancelled');
  };

  return (
    <ConsoleDialog title={org.name} onClose={onClose}>
      <p className="console-text" style={{ margin: '0 0 8px' }}>
        {org.email}{org.phone ? <> · <a href={`tel:${org.phone}`}>{org.phone}</a></> : null} · <span className={`console-badge badge-${org.status}`}>{statusLabel(org.status)}</span>
      </p>
      <p className="console-text" style={{ margin: '0 0 14px' }}>
        {planName(sub)} · <b>{statusLabel(sub.status)}</b> · ends {fmtDate(sub.current_period_end || sub.trial_ends_at)}
        {sub.cancel_at_period_end && <> · <span className="console-badge badge-past_due">Cancels at period end</span></>}
      </p>
      <div style={{ marginBottom: 14 }}>
        <CopyField label="Org ID" value={String(org.id ?? '')} />
      </div>
      {invoices.length > 0 && (
        <div style={{ marginBottom: 14 }}>
          <div className="console-label" style={{ marginBottom: 6 }}>Invoices</div>
          {invoices.map((inv: any) => (
            <div className="console-item" key={inv.id} style={{ padding: '8px 10px' }}>
              <div className="item-sub">{inv.invoice_no} · {fmtInr(inv.gross_paise ?? inv.amount_paise)}</div>
              <button className="console-btn console-btn-ghost console-btn-sm" aria-label={`Download invoice ${inv.invoice_no} as PDF`}
                onClick={() => downloadInvoicePdf(inv.id, 'admin')}>PDF</button>
            </div>
          ))}
        </div>
      )}
      {mode === 'activate' && (
        <form className="console-form" style={{ marginBottom: 14 }} onSubmit={activate}>
          {formError && <div className="console-banner console-banner-error" role="alert">{formError}</div>}
          <div className="console-inline-form">
            <div className="console-field">
              <label htmlFor="act-method">Payment method</label>
              <select id="act-method" className="console-select" value={form.method}
                onChange={(e) => setForm((f) => ({ ...f, method: e.target.value }))}>
                <option value="bank">Bank transfer</option>
                <option value="upi">UPI</option>
                <option value="razorpay">Razorpay</option>
              </select>
            </div>
            <div className="console-field">
              <label htmlFor="act-days">Period (days)</label>
              <input id="act-days" className="console-input" type="number" min={1} inputMode="numeric"
                placeholder={planDays ? String(planDays) : 'Plan default'} value={form.period_days}
                onChange={(e) => setForm((f) => ({ ...f, period_days: e.target.value }))} />
            </div>
            <div className="console-field">
              <label htmlFor="act-amount">Amount received (₹)</label>
              <input id="act-amount" className="console-input" type="number" min={0} step="0.01" inputMode="decimal"
                placeholder={planPrice ?? ''} aria-describedby="act-amount-hint"
                value={form.amount_rupees} onChange={(e) => setForm((f) => ({ ...f, amount_rupees: e.target.value }))} />
              <span id="act-amount-hint" className="console-help">Leave blank to use the plan price{planPrice ? ` (${planPrice})` : ''}.</span>
            </div>
          </div>
          <div className="console-field">
            <label htmlFor="act-ref">Payment reference</label>
            <input id="act-ref" className="console-input" placeholder="e.g. NEFT UTR or UPI ref" value={form.reference}
              onChange={(e) => setForm((f) => ({ ...f, reference: e.target.value }))} />
          </div>
          <div className="console-field">
            <label htmlFor="act-notes">Notes</label>
            <input id="act-notes" className="console-input" value={form.notes}
              onChange={(e) => setForm((f) => ({ ...f, notes: e.target.value }))} />
          </div>
          <button className="console-btn console-btn-primary" disabled={busy}>
            Record payment &amp; activate
          </button>
        </form>
      )}
      {mode === 'extend' && (
        <form className="console-form console-inline-form" style={{ marginBottom: 14 }} onSubmit={extend}>
          <div className="console-field">
            <label htmlFor="ext-days">Extend by (days)</label>
            <input id="ext-days" className="console-input" type="number" min={1} inputMode="numeric" placeholder="30" value={form.period_days}
              onChange={(e) => setForm((f) => ({ ...f, period_days: e.target.value }))} />
          </div>
          <button className="console-btn console-btn-primary" disabled={busy}>
            Extend
          </button>
        </form>
      )}
      <div className="console-row">
        <button type="button" className="console-btn console-btn-primary" aria-expanded={mode === 'activate'}
          onClick={() => setMode(mode === 'activate' ? null : 'activate')}>
          {mode === 'activate' ? 'Close payment form' : 'Activate / renew'}
        </button>
        <button type="button" className="console-btn console-btn-ghost" aria-expanded={mode === 'extend'}
          onClick={() => setMode(mode === 'extend' ? null : 'extend')}>
          {mode === 'extend' ? 'Close extend form' : 'Extend'}
        </button>
        <button type="button" className="console-btn console-btn-danger" disabled={busy} onClick={suspend}>
          Suspend
        </button>
        <button type="button" className="console-btn console-btn-danger" disabled={busy} onClick={cancelOrg}>
          Cancel organization
        </button>
        <button type="button" className="console-btn console-btn-ghost" onClick={onClose}>Close</button>
      </div>
    </ConsoleDialog>
  );
};
